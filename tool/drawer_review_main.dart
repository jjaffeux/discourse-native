import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _DrawerReviewApp());
}

class _DrawerReviewApp extends StatefulWidget {
  const _DrawerReviewApp();

  @override
  State<_DrawerReviewApp> createState() => _DrawerReviewAppState();
}

class _DrawerReviewAppState extends State<_DrawerReviewApp> {
  bool _dark = false;
  bool _rtl = false;
  bool _large = false;
  bool _reducedMotion = false;
  var _snap = const DDrawerSnapPoint.pixels(240);
  int _pagePresses = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _dark ? AppTheme.dark : AppTheme.light,
    home: Builder(
      builder: (context) => Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(_large ? 2 : 1),
            disableAnimations: _reducedMotion,
          ),
          child: Scaffold(
            appBar: AppBar(title: const Text('Drawer review — exact source')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _toggle('Light / dark', () => _dark = !_dark),
                  _toggle('LTR / RTL', () => _rtl = !_rtl),
                  _toggle('100 / 200%', () => _large = !_large),
                  _toggle(
                    'Motion / reduced',
                    () => _reducedMotion = !_reducedMotion,
                  ),
                  _basicDrawer(),
                  _sideDrawer(),
                  _snapDrawer(),
                  _nonModalDrawer(),
                  DButton(
                    onPressed: () => setState(() => _pagePresses++),
                    variant: DButtonVariant.outline,
                    label: Text('Page action · $_pagePresses'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _toggle(String label, VoidCallback update) => DButton(
    onPressed: () => setState(update),
    variant: DButtonVariant.outline,
    label: Text(label),
  );

  Widget _basicDrawer() => DDrawer<void>(
    showSwipeHandle: true,
    trigger: DDrawerTrigger(
      builder: (_, open) => DButton(
        onPressed: open,
        variant: DButtonVariant.secondary,
        label: const Text('Bottom drawer'),
      ),
    ),
    content: _content('Pick a delivery time'),
  );

  Widget _sideDrawer() => DDrawer<void>(
    swipeDirection: DDrawerSwipeDirection.end,
    showSwipeHandle: true,
    trigger: DDrawerTrigger(
      builder: (_, open) => DButton(
        onPressed: open,
        variant: DButtonVariant.secondary,
        label: const Text('Logical side drawer'),
      ),
    ),
    content: _content('Logical side drawer'),
  );

  Widget _snapDrawer() => DDrawer<void>(
    snapPoints: const [
      DDrawerSnapPoint.pixels(240),
      DDrawerSnapPoint.fraction(1),
    ],
    snapPoint: _snap,
    onSnapPointChanged: (details) {
      if (details.point != null) setState(() => _snap = details.point!);
    },
    showSwipeHandle: true,
    trigger: DDrawerTrigger(
      builder: (_, open) => DButton(
        onPressed: open,
        variant: DButtonVariant.outline,
        label: const Text('Snap drawer'),
      ),
    ),
    content: _content('Snap points', fill: true),
  );

  Widget _nonModalDrawer() => DDrawer<void>(
    modalMode: DDrawerModalMode.nonModal,
    disablePointerDismissal: true,
    swipeDirection: DDrawerSwipeDirection.right,
    trigger: DDrawerTrigger(
      builder: (_, open) => DButton(
        onPressed: open,
        variant: DButtonVariant.outline,
        label: const Text('Non modal'),
      ),
    ),
    content: _content('Non modal drawer', fill: true),
  );

  DDrawerContent _content(String title, {bool fill = false}) => DDrawerContent(
    semanticLabel: title,
    children: [
      DDrawerHeader(
        children: [
          DDrawerTitle(child: Text(title)),
          const DDrawerDescription(
            child: Text('Drag the panel, test focus, then close it.'),
          ),
        ],
      ),
      DDrawerScrollArea(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DInput(labelText: 'Email', initialValue: 'review@example.com'),
            SizedBox(height: fill ? 260 : 80),
          ],
        ),
      ),
      DDrawerFooter(
        children: [
          DDrawerClose<void>(
            builder: (_, close) =>
                DButton(onPressed: close, label: const Text('Close')),
          ),
        ],
      ),
    ],
  );
}
