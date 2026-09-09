import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/adaptive_dialog_action.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Local-data-only native review entrypoint for Alert Dialog. It mounts the
/// complete production styleguide plus the real application confirmation
/// adapter used by migrated callers. It performs no network or account work.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _AlertDialogReviewApp());
}

class _AlertDialogReviewApp extends StatelessWidget {
  const _AlertDialogReviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: const _AlertDialogReviewHome(),
  );
}

class _AlertDialogReviewHome extends StatefulWidget {
  const _AlertDialogReviewHome();

  @override
  State<_AlertDialogReviewHome> createState() => _AlertDialogReviewHomeState();
}

class _AlertDialogReviewHomeState extends State<_AlertDialogReviewHome> {
  String _status = 'No local decision yet';

  Future<void> _confirm({required bool destructive}) async {
    final result = await showDiscourseAlertDialog<bool>(
      context: context,
      title: Text(
        destructive ? 'Remove Discourse Meta?' : 'Mark notifications as read?',
      ),
      description: Text(
        destructive
            ? 'This signs out of meta.discourse.org and removes it from the rail. The local fixture performs no account operation.'
            : 'Mark 14 local fixture notifications as read?',
      ),
      cancelLabel: const Text('Cancel'),
      actionLabel: Text(destructive ? 'Remove' : 'Mark as read'),
      cancelResult: false,
      actionResult: true,
      actionVariant: destructive
          ? DButtonVariant.destructive
          : DButtonVariant.primary,
    );
    if (!mounted) return;
    setState(
      () => _status = switch (result) {
        true => 'Confirmed locally; no mutation performed',
        false => 'Cancelled explicitly',
        null => 'Cancelled with Escape',
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alert Dialog native review')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            DButton(
              label: const Text('Complete component styleguide'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const ComponentStyleguidePage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DButton(
              label: const Text('Production destructive confirmation'),
              variant: DButtonVariant.destructive,
              onPressed: () => _confirm(destructive: true),
            ),
            const SizedBox(height: 8),
            DButton(
              label: const Text('Production regular confirmation'),
              variant: DButtonVariant.outline,
              onPressed: () => _confirm(destructive: false),
            ),
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(_status)),
          ],
        ),
      ),
    ),
  );
}
