import 'package:flutter/material.dart';

import 'discourse_ui.dart';
import 'src/macos_launch_screen.dart';
import 'src/styleguide/examples/resizable_examples.dart';
import 'src/styleguide/styleguide_page.dart';
import 'src/theme/app_theme.dart';

/// Isolated native review: actual production adapters with in-memory state only.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DButton(
                    label: const Text('Open component styleguide'),
                    onPressed: () => showComponentStyleguide(context),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      for (final example in resizableExamples.examples) ...[
                        Text(
                          example.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        example.builder(context),
                        const SizedBox(height: 32),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
