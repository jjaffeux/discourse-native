// Offline design study: flutter run -d macos -t tool/sidebar_spacing_mockup.dart
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const SidebarSpacingMockup());
}

class SidebarSpacingMockup extends StatefulWidget {
  const SidebarSpacingMockup({super.key, this.initialDark = true});
  final bool initialDark;

  @override
  State<SidebarSpacingMockup> createState() => _SidebarSpacingMockupState();
}

class _SidebarSpacingMockupState extends State<SidebarSpacingMockup> {
  late bool _dark = widget.initialDark;
  String _selected = 'Topics';
  String _view = 'Compare';

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: (_dark ? AppTheme.dark : AppTheme.light).copyWith(
      platform: TargetPlatform.macOS,
    ),
    builder: (context, child) => DFocusHighlight(child: child!),
    home: Builder(
      builder: (context) => ColoredBox(
        color: DTokens.of(context).background,
        child: SafeArea(
          child: DScrollArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DText(
                        'SIDEBAR / SPACING STUDY',
                        variant: DTextVariant.muted,
                      ),
                      const SizedBox(height: 8),
                      const DText(
                        'A little more room.',
                        variant: DTextVariant.h1,
                      ),
                      const SizedBox(height: 8),
                      const DText(
                        'The same sidebar, with more space between rows. Inspired by your Discord reference.',
                        variant: DTextVariant.muted,
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DToggleGroup<String>(
                            semanticLabel: 'Preview layout',
                            allowEmptySelection: false,
                            values: [_view],
                            onChanged: (values) =>
                                setState(() => _view = values.single),
                            items: [
                              for (final label in [
                                'Compare',
                                'Current',
                                'Comfortable',
                                'Relaxed',
                              ])
                                DToggleGroupItem(
                                  value: label,
                                  child: Text(label),
                                ),
                            ],
                          ),
                          DToggleGroup<bool>(
                            semanticLabel: 'Appearance',
                            allowEmptySelection: false,
                            values: [_dark],
                            onChanged: (values) =>
                                setState(() => _dark = values.single),
                            items: const [
                              DToggleGroupItem(
                                value: false,
                                child: Text('Light'),
                              ),
                              DToggleGroupItem(
                                value: true,
                                child: Text('Dark'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Wrap(
                        spacing: 28,
                        runSpacing: 28,
                        children: [
                          for (final option in _options)
                            if (_view == 'Compare' || _view == option.name)
                              SizedBox(
                                width: 272,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      spacing: 8,
                                      children: [
                                        DText(
                                          option.name,
                                          variant: DTextVariant.h4,
                                        ),
                                        if (option.gap == 6)
                                          const DBadge(
                                            child: Text('Suggested'),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    DText(
                                      '32 px row · ${option.gap.toInt()} px gap',
                                      variant: DTextVariant.muted,
                                    ),
                                    const SizedBox(height: 16),
                                    DCard(
                                      spacing: 0,
                                      child: SizedBox(
                                        height: 724,
                                        child: _SidebarPreview(
                                          gap: option.gap,
                                          selected: _selected,
                                          onSelect: (value) =>
                                              setState(() => _selected = value),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    DText(
                                      option.note,
                                      variant: DTextVariant.muted,
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const DSeparator(),
                      const SizedBox(height: 16),
                      const DText(
                        'Hover and select rows to compare the feel. Each sidebar scrolls independently.',
                        variant: DTextVariant.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _options = [
  (name: 'Current', gap: 1.0, note: 'Compact. A 33 px rhythm between labels.'),
  (name: 'Comfortable', gap: 6.0, note: 'More breathing room. A 38 px rhythm.'),
  (
    name: 'Relaxed',
    gap: 10.0,
    note: 'Airier, with more scrolling. A 42 px rhythm.',
  ),
];

class _SidebarPreview extends StatelessWidget {
  const _SidebarPreview({
    required this.gap,
    required this.selected,
    required this.onSelect,
  });
  final double gap;
  final String selected;
  final ValueChanged<String> onSelect;

  Widget _row(
    String label,
    Widget icon, {
    String? badge,
    double iconSize = 18,
  }) => Padding(
    padding: EdgeInsets.only(bottom: gap),
    child: DSidebarMenuItem(
      badge: badge == null ? null : DSidebarMenuBadge(child: Text(badge)),
      child: DSidebarMenuButton(
        size: DSidebarMenuButtonSize.large,
        iconSize: iconSize,
        icon: Center(child: icon),
        isActive: selected == label,
        onPressed: () => onSelect(label),
        child: Text(label),
      ),
    ),
  );

  Widget _group(String? title, List<Widget> rows) => DSidebarGroup(
    label: title == null ? null : DSidebarGroupLabel(child: Text(title)),
    child: DSidebarMenu(children: rows),
  );

  @override
  Widget build(BuildContext context) => DSidebarProvider(
    child: DSidebar(
      width: 272,
      collapsible: DSidebarCollapsible.none,
      semanticLabel: 'Sidebar with ${gap.toInt()} pixel spacing',
      header: DSidebarHeader(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            spacing: 10,
            children: [
              const DAvatar(
                decorative: true,
                fallback: DAvatarFallback(child: Text('D')),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DText('Discourse Meta', variant: DTextVariant.small),
                    Text(
                      'meta.discourse.org',
                      style: TextStyle(
                        fontSize: 12,
                        color: DTokens.of(context).mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      child: DSidebarContent(
        children: [
          _group(null, [
            _row('Topics', const DIcon(DIcons.layerGroup, size: 16)),
            _row('My posts', const DIcon(DIcons.comment, size: 16)),
            _row(
              'Messages',
              const DIcon(DIcons.envelope, size: 16),
              badge: '4',
            ),
            _row('Bookmarks', const DIcon(DIcons.bookmark, size: 16)),
          ]),
          _group('Categories', [
            _row(
              'General',
              const DIcon(DIcons.folder, size: 16, color: Color(0xff7d9cec)),
            ),
            _row(
              'Support',
              const DIcon(DIcons.folder, size: 16, color: Color(0xff6baa90)),
            ),
            _row(
              'Feature',
              const DIcon(DIcons.folder, size: 16, color: Color(0xffbb98d0)),
            ),
          ]),
          _group('Channels', [
            _row('general', const DIcon(DIcons.comments, size: 16), badge: '3'),
            _row('design', const DIcon(DIcons.comments, size: 16)),
            _row('off-topic', const DIcon(DIcons.comments, size: 16)),
          ]),
          _group('Direct messages', [
            for (final (label, initials) in [
              ('Maya Chen', 'M'),
              ('Sam Rivera', 'S'),
              ('Alex Morgan', 'A'),
            ])
              _row(
                label,
                DAvatar(
                  dimension: 18,
                  size: DAvatarSize.sm,
                  decorative: true,
                  fallback: DAvatarFallback(child: Text(initials)),
                ),
              ),
          ]),
        ],
      ),
    ),
  );
}
