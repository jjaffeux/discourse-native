// Local-data review only. No accounts, networking, persistence, or plugins.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/command_menu.dart';
import 'package:discourse_native/src/styleguide/examples/command_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const CommandReviewApp());
}

class CommandReviewApp extends StatefulWidget {
  const CommandReviewApp({super.key});
  @override
  State<CommandReviewApp> createState() => _CommandReviewAppState();
}

class _CommandReviewAppState extends State<CommandReviewApp> {
  StyleguideTheme _theme = StyleguideTheme.light;
  bool _rtl = false;
  bool _largeText = false;
  bool _reducedMotion = false;
  bool _mono = false;

  @override
  Widget build(BuildContext context) {
    final baseTheme = _theme.resolve(AppTheme.light);
    final theme = _mono
        ? baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: 'JetBrains Mono'),
            primaryTextTheme: baseTheme.primaryTextTheme.apply(
              fontFamily: 'JetBrains Mono',
            ),
          )
        : baseTheme;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_largeText ? 2 : 1),
          disableAnimations: _reducedMotion,
        ),
        child: Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Command review — local data')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in StyleguideTheme.values)
                  DButton(
                    size: DButtonSize.small,
                    variant: _theme == choice
                        ? DButtonVariant.primary
                        : DButtonVariant.outline,
                    onPressed: () => setState(() => _theme = choice),
                    label: Text(choice.label),
                  ),
                DButton(
                  size: DButtonSize.small,
                  variant: DButtonVariant.outline,
                  onPressed: () => setState(() => _rtl = !_rtl),
                  label: Text(_rtl ? 'RTL on' : 'RTL off'),
                ),
                DButton(
                  size: DButtonSize.small,
                  variant: DButtonVariant.outline,
                  onPressed: () => setState(() => _largeText = !_largeText),
                  label: Text(_largeText ? '200% text' : '100% text'),
                ),
                DButton(
                  size: DButtonSize.small,
                  variant: DButtonVariant.outline,
                  onPressed: () => setState(() => _mono = !_mono),
                  label: Text(_mono ? 'Mono font' : 'App font'),
                ),
                DButton(
                  size: DButtonSize.small,
                  variant: DButtonVariant.outline,
                  onPressed: () =>
                      setState(() => _reducedMotion = !_reducedMotion),
                  label: Text(
                    _reducedMotion ? 'Reduced motion' : 'Motion enabled',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _ProductionAdapterCard(),
            const SizedBox(height: 20),
            _LiveDialogCard(
              onPaletteAndRadius: () => setState(
                () => _theme = _theme == StyleguideTheme.plum
                    ? StyleguideTheme.light
                    : StyleguideTheme.plum,
              ),
              onFont: () => setState(() => _mono = !_mono),
              onDirection: () => setState(() => _rtl = !_rtl),
              onTextScale: () => setState(() => _largeText = !_largeText),
              onMotion: () => setState(() => _reducedMotion = !_reducedMotion),
            ),
            const SizedBox(height: 20),
            for (final example in commandExamples.examples) ...[
              _ExampleCard(example: example),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveDialogCard extends StatefulWidget {
  const _LiveDialogCard({
    required this.onPaletteAndRadius,
    required this.onFont,
    required this.onDirection,
    required this.onTextScale,
    required this.onMotion,
  });

  final VoidCallback onPaletteAndRadius;
  final VoidCallback onFont;
  final VoidCallback onDirection;
  final VoidCallback onTextScale;
  final VoidCallback onMotion;

  @override
  State<_LiveDialogCard> createState() => _LiveDialogCardState();
}

class _LiveDialogCardState extends State<_LiveDialogCard> {
  final _dialog = DDialogController<String>();
  String _lastAction = 'No live change requested';

  void _run(String action) {
    switch (action) {
      case 'palette':
        widget.onPaletteAndRadius();
      case 'font':
        widget.onFont();
      case 'direction':
        widget.onDirection();
      case 'scale':
        widget.onTextScale();
      case 'motion':
        widget.onMotion();
      case 'close':
        _dialog.close(action);
    }
    if (mounted) setState(() => _lastAction = 'Requested $action');
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live open-dialog updates',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'These command rows keep the dialog open while changing inherited review settings.',
          ),
          const SizedBox(height: 12),
          DCommandDialog<String>(
            controller: _dialog,
            trigger: DDialogTrigger(
              builder: (context, open) => DButton(
                variant: DButtonVariant.outline,
                onPressed: open,
                label: const Text('Open live-update palette'),
              ),
            ),
            command: DCommand<String>(
              onSelected: _run,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DCommandInput<String>(),
                  DCommandList<String>(
                    children: [
                      DCommandGroup<String>(
                        heading: Text('Change while open'),
                        items: [
                          DCommandItem(
                            value: 'palette',
                            child: Text('Toggle light / Plum radius'),
                          ),
                          DCommandItem(
                            value: 'font',
                            child: Text('Toggle app / mono font'),
                          ),
                          DCommandItem(
                            value: 'direction',
                            child: Text('Toggle LTR / RTL'),
                          ),
                          DCommandItem(
                            value: 'scale',
                            child: Text('Toggle 100% / 200% text'),
                          ),
                          DCommandItem(
                            value: 'motion',
                            child: Text('Toggle motion preference'),
                          ),
                          DCommandItem(
                            value: 'close',
                            child: Text('Close live-update palette'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(_lastAction),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _dialog.dispose();
    super.dispose();
  }
}

class _ProductionAdapterCard extends StatefulWidget {
  const _ProductionAdapterCard();
  @override
  State<_ProductionAdapterCard> createState() => _ProductionAdapterCardState();
}

class _ProductionAdapterCardState extends State<_ProductionAdapterCard> {
  String _result = 'No shell action selected';

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actual shell CommandMenuAnchor adapter',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Uses the production anchor/route and the migrated public Command rows with local actions.',
          ),
          const SizedBox(height: 12),
          CommandMenuAnchor<String>(
            title: 'Topic actions',
            options: const [
              CommandMenuOption(
                value: 'pin',
                label: 'Pin topic',
                icon: DIcons.thumbtack,
              ),
              CommandMenuOption(
                value: 'close',
                label: 'Close topic',
                icon: DIcons.lock,
              ),
              CommandMenuOption(
                value: 'delete',
                label: 'Delete topic',
                icon: DIcons.trashCan,
                dividerBefore: true,
                destructive: true,
              ),
            ],
            onSelected: (value) => setState(() => _result = 'Selected $value'),
            builder: (context, open) => DButton(
              variant: DButtonVariant.outline,
              onPressed: open,
              icon: const DIcon(DIcons.ellipsis),
              label: const Text('Open topic actions'),
            ),
          ),
          const SizedBox(height: 8),
          Text(_result),
        ],
      ),
    ),
  );
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.example});
  final StyleguideExample example;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(example.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(example.description),
          const SizedBox(height: 16),
          Center(child: Builder(builder: example.builder)),
        ],
      ),
    ),
  );
}
