// Offline native review of the actual Date Picker styleguide surface.
import 'package:discourse_native/src/styleguide/examples/date_picker_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() => runApp(const _DatePickerReviewApp());

class _DatePickerReviewApp extends StatelessWidget {
  const _DatePickerReviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    darkTheme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
    home: const _ReviewPage(),
  );
}

class _ReviewPage extends StatelessWidget {
  const _ReviewPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Date Picker review')),
    body: ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: datePickerExamples.examples.length,
      separatorBuilder: (_, _) => const SizedBox(height: 32),
      itemBuilder: (context, index) {
        final example = datePickerExamples.examples[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(example.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Builder(builder: example.builder),
          ],
        );
      },
    ),
  );
}
