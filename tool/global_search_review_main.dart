import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/global_search_fixtures.dart';

/// Offline native review of the production shell, header, and global search.
/// Search for design/keyboard/search; missing/failure exercise other states.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = createGlobalSearchFixtureController();
  await shell.load();
  shell.selectInstance(0);
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_GlobalSearchReview(shell: shell));
}

class _GlobalSearchReview extends StatefulWidget {
  const _GlobalSearchReview({required this.shell});

  final ShellController shell;

  @override
  State<_GlobalSearchReview> createState() => _GlobalSearchReviewState();
}

class _GlobalSearchReviewState extends State<_GlobalSearchReview> {
  bool _dark = true;
  bool _narrow = false;
  bool _largeText = false;
  bool _rtl = false;

  @override
  void dispose() {
    widget.shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DButton(
                      label: Text(_dark ? 'Light palette' : 'Dark palette'),
                      variant: DButtonVariant.outline,
                      onPressed: () => setState(() => _dark = !_dark),
                    ),
                    DButton(
                      label: Text(_narrow ? 'Wide layout' : 'Narrow layout'),
                      variant: DButtonVariant.outline,
                      onPressed: () => setState(() => _narrow = !_narrow),
                    ),
                    DButton(
                      label: Text(_largeText ? '100% text' : '200% text'),
                      variant: DButtonVariant.outline,
                      onPressed: () => setState(() => _largeText = !_largeText),
                    ),
                    DButton(
                      label: Text(_rtl ? 'LTR' : 'RTL'),
                      variant: DButtonVariant.outline,
                      onPressed: () => setState(() => _rtl = !_rtl),
                    ),
                    DButton(
                      label: const Text('Meta · chat enabled'),
                      variant: DButtonVariant.outline,
                      onPressed: () => widget.shell.selectInstance(0),
                    ),
                    DButton(
                      label: const Text('Community · chat disabled'),
                      variant: DButtonVariant.outline,
                      onPressed: () => widget.shell.selectInstance(1),
                    ),
                    DButton(
                      label: const Text('Open search'),
                      onPressed: widget.shell.search.requestFocus,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: _narrow ? 390 : double.infinity,
                    child: LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: constraints.biggest,
                          textScaler: TextScaler.linear(_largeText ? 2 : 1),
                        ),
                        child: Directionality(
                          textDirection: _rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Navigator(
                            onGenerateRoute: (_) => MaterialPageRoute<void>(
                              builder: (_) => const AdaptiveShell(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
