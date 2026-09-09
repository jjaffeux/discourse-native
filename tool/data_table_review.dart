import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/styleguide/examples/data_table_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Offline exact-widget fixture for the serialized Data Table native review.
/// It makes no account, store, clipboard, or network request.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _DataTableReviewApp());
}

class _DataTableReviewApp extends StatelessWidget {
  const _DataTableReviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: Scaffold(
      appBar: AppBar(title: const Text('Data Table review')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: const DataTableInteractiveExample(),
          ),
        ),
      ),
    ),
  );
}
