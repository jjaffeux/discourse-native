import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell_scope.dart';

/// The landing surface for an otherwise empty forum tab.
class NewTabPage extends StatefulWidget {
  const NewTabPage({super.key, required this.onBrowseTopics});

  final VoidCallback onBrowseTopics;

  @override
  State<NewTabPage> createState() => _NewTabPageState();
}

class _NewTabPageState extends State<NewTabPage> {
  static const _dismissedKey = 'discourse_native.panel_tutorial_dismissed';
  bool? _dismissed;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreference());
  }

  Future<void> _loadPreference() async {
    bool dismissed;
    try {
      dismissed =
          (await SharedPreferences.getInstance()).getBool(_dismissedKey) ??
          false;
    } catch (_) {
      dismissed = false;
    }
    if (mounted) setState(() => _dismissed = dismissed);
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    try {
      await (await SharedPreferences.getInstance()).setBool(
        _dismissedKey,
        true,
      );
    } catch (_) {
      // The current tab still honors the choice if local storage is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Align(
      alignment: AlignmentDirectional.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(DSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DSpacing.lg,
            children: [
              Text(
                'New tab',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (_dismissed == false &&
                  (ShellScope.maybeRead(context)?.desktopPanelsEnabled ?? true))
                DCard(
                  children: [
                    Text(
                      'Work with two panels',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Choose where each link opens. A regular click stays in '
                      'the current tab.',
                    ),
                    const _PanelGestureHint(
                      keys: ['Middle click'],
                      description: 'Open a new tab in the current panel',
                    ),
                    const _PanelGestureHint(
                      keys: ['Shift', 'Click'],
                      description: 'Open in the secondary panel',
                    ),
                    const _PanelGestureHint(
                      keys: ['Shift', 'Middle click'],
                      description: 'Open a new tab in the secondary panel',
                    ),
                    const Text(
                      'Right-click a link to choose the main or secondary '
                      'panel and whether to use a new tab. Drag a tab between '
                      'panels, or right-click its tab to move it.',
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DButton(
                        key: const ValueKey('dismiss-panel-tutorial'),
                        onPressed: _dismiss,
                        variant: DButtonVariant.outline,
                        label: const Text("Don't show this again"),
                      ),
                    ),
                  ],
                ),
              if (_dismissed != null)
                DButton(
                  onPressed: widget.onBrowseTopics,
                  label: const Text('Browse latest topics'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PanelGestureHint extends StatelessWidget {
  const _PanelGestureHint({required this.keys, required this.description});

  final List<String> keys;
  final String description;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: DSpacing.sm,
    runSpacing: DSpacing.xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [for (final key in keys) DKbd(key), Text(description)],
  );
}
