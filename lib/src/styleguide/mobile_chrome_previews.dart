import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';

@Preview(
  name: 'Mobile dock — light',
  group: 'Mobile chrome',
  size: Size(390, 720),
)
Widget mobileDockLightPreview() => _preview(AppTheme.light);
@Preview(
  name: 'Mobile dock — dark',
  group: 'Mobile chrome',
  size: Size(390, 720),
)
Widget mobileDockDarkPreview() => _preview(AppTheme.dark);
@Preview(
  name: 'Mobile dock — narrow',
  group: 'Mobile chrome',
  size: Size(320, 720),
)
Widget mobileDockNarrowPreview() => _preview(AppTheme.light);
@Preview(
  name: 'Mobile dock — folded',
  group: 'Mobile chrome',
  size: Size(390, 720),
)
Widget mobileDockFoldedPreview() => _preview(AppTheme.light, collapsed: true);

@Preview(
  name: 'Chat composer dock',
  group: 'Mobile chrome',
  size: Size(390, 720),
)
Widget mobileChatComposerPreview() => _preview(AppTheme.light, chat: true);

Widget _preview(ThemeData theme, {bool collapsed = false, bool chat = false}) =>
    MaterialApp(
      theme: theme.copyWith(platform: TargetPlatform.iOS),
      home: MobileChromeExample(
        initiallyCollapsed: collapsed,
        chatComposer: chat,
      ),
    );

/// Native preview entry point; scrolling and pressing the folded dock are live.
void main() => runApp(mobileDockLightPreview());

class MobileChromeExample extends StatefulWidget {
  const MobileChromeExample({
    super.key,
    this.initiallyCollapsed = false,
    this.chatComposer = false,
  });
  final bool initiallyCollapsed;
  final bool chatComposer;
  @override
  State<MobileChromeExample> createState() => _MobileChromePreviewState();
}

class _MobileChromePreviewState extends State<MobileChromeExample> {
  late int _selected = widget.chatComposer ? 2 : 1;
  final _draft = TextEditingController();
  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  late bool _initialFold = widget.initiallyCollapsed;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Color.lerp(
      DTokens.of(context).background,
      Colors.black,
      .14,
    ),
    body: SafeArea(
      child: Center(
        child: SizedBox(
          width: 390,
          child: DScrollChrome(
            identity: _selected,
            floatingFooter: true,
            footerBuilder: (hidden) => Builder(
              builder: (context) {
                final geometry = DMobileDockGeometry.of(context);
                return Padding(
                  padding: geometry.margin,
                  child: DMobileDock(
                    geometry: geometry,
                    collapsed: hidden || _initialFold,
                    places: [
                      for (final (index, name) in [
                        'Start',
                        'Topics',
                        'Chat',
                        'Inbox',
                        'Users',
                        'Events',
                      ].indexed)
                        DMobileDockItem(
                          label: name,
                          icon: DIcon(
                            [
                              DIcons.house,
                              DIcons.layerGroup,
                              DIcons.comment,
                              DIcons.inbox,
                              DIcons.users,
                              DIcons.users,
                            ][index],
                          ),
                          selected: _selected == index,
                          badge: index == 2
                              ? const DBadge.overlay(child: Text('12'))
                              : null,
                          onPressed: () => setState(() => _selected = index),
                        ),
                    ],
                    more: DMobileDockItem(
                      icon: const DIcon(DIcons.ellipsisVertical),
                      label: 'More',
                      bare: true,
                      onPressed: () {},
                    ),
                    collapsedDestination: DMobileDockItem(
                      icon: const DIcon(DIcons.layerGroup),
                      label: 'Reveal navigation',
                      collapsed: true,
                      onPressed: () {
                        setState(() => _initialFold = false);
                        DScrollChrome.maybeOf(context)?.reveal();
                      },
                    ),
                    action: DMobileDockAction(
                      icon: const DIcon(DIcons.penToSquare),
                      label: 'New topic',
                      onPressed: () {},
                    ),
                  ),
                );
              },
            ),
            child: DPageSurface.scrollable(
              framed: false,
              hideHeaderOnScroll: true,
              footer: widget.chatComposer
                  ? DComposerDock(
                      builder: (context, compact) => DCard(
                        spacing: 0,
                        borderRadius: DInputGroup.composerBorderRadius,
                        child: DInputGroup(
                          variant: DInputGroupVariant.composer,
                          compact: compact,
                          borderless: true,
                          action: DButton.iconOnly(
                            icon: const DIcon(DIcons.paperPlane, size: 12),
                            size: DButtonSize.toolbar,
                            tooltip: 'Send message',
                            onPressed: _draft.clear,
                          ),
                          children: [
                            DInputGroupTextarea(
                              controller: _draft,
                              hintText: 'Message #design',
                              minLines: 1,
                              maxLines: compact ? 1 : 4,
                            ),
                            DInputGroupAddon(
                              alignment: DInputGroupAddonAlignment.blockEnd,
                              child: DButton.iconOnly(
                                icon: const DIcon(DIcons.plus),
                                tooltip: 'Add to message',
                                variant: DButtonVariant.ghost,
                                size: DButtonSize.toolbar,
                                onPressed: () {},
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
              header: const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(
                  'Topics',
                  style: TextStyle(
                    fontSize: DiscourseTypography.xxl,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              headerControls: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Row(
                  children: [
                    DButton(
                      label: const Text('Latest'),
                      variant: DButtonVariant.quietSelected,
                      size: DButtonSize.filter,
                      onPressed: () {},
                    ),
                    const SizedBox(width: 8),
                    DButton(
                      label: const Text('Categories'),
                      variant: DButtonVariant.quiet,
                      size: DButtonSize.filter,
                      onPressed: () {},
                    ),
                    const Spacer(),
                    DButton.iconOnly(
                      icon: const DIcon(DNativeIcons.sliders),
                      tooltip: 'Filters',
                      size: DButtonSize.filter,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              bodyBuilder: (context, header) => ListView(
                padding: EdgeInsets.only(
                  bottom: DScrollChrome.bottomInsetOf(context),
                ),
                children: [
                  header.spacer,
                  for (var i = 1; i <= 30; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Community discussion $i',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'A topic preview on the shared mobile canvas.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          const DSeparator(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
