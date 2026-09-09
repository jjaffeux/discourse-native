// Offline native review of the exact Date Picker examples and Local Date
// composer adoption. All state and actions are local to this process.
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/styleguide/examples/date_picker_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LocalDateEnvironment.instance.ensureDatabase();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _DatePickerReviewApp());
}

class _DatePickerReviewApp extends StatefulWidget {
  const _DatePickerReviewApp();

  @override
  State<_DatePickerReviewApp> createState() => _DatePickerReviewAppState();
}

class _DatePickerReviewAppState extends State<_DatePickerReviewApp> {
  var _theme = StyleguideTheme.light;
  var _example = 0;
  var _localDate = false;
  var _rtl = false;
  var _reducedMotion = false;
  var _scale = 1.0;
  var _width = 720.0;

  @override
  Widget build(BuildContext context) {
    final example = datePickerExamples.examples[_example];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme.resolve(AppTheme.light),
      home: Scaffold(
        appBar: AppBar(title: const Text('Date Picker exact-source review')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<StyleguideTheme>(
                    value: _theme,
                    onChanged: (value) {
                      if (value != null) setState(() => _theme = value);
                    },
                    items: [
                      for (final theme in StyleguideTheme.values.skip(1))
                        DropdownMenuItem(
                          value: theme,
                          child: Text(theme.label),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => setState(() => _rtl = !_rtl),
                    child: Text(_rtl ? 'RTL' : 'LTR'),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _scale = _scale == 1 ? 2 : 1),
                    child: Text('${(_scale * 100).round()}% text'),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _width = _width == 360 ? 720 : 360),
                    child: Text('${_width.round()}px'),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _reducedMotion = !_reducedMotion),
                    child: Text(
                      _reducedMotion ? 'Reduced motion' : 'Full motion',
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _localDate = !_localDate),
                    child: Text(
                      _localDate ? 'Date Picker examples' : 'Local Date',
                    ),
                  ),
                  if (!_localDate) ...[
                    IconButton(
                      tooltip: 'Previous example',
                      onPressed: () => setState(
                        () => _example =
                            (_example - 1) % datePickerExamples.examples.length,
                      ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(example.title),
                    IconButton(
                      tooltip: 'Next example',
                      onPressed: () => setState(
                        () => _example =
                            (_example + 1) % datePickerExamples.examples.length,
                      ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: SingleChildScrollView(
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(_scale),
                        disableAnimations: _reducedMotion,
                      ),
                      child: Directionality(
                        textDirection: _rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: SizedBox(
                          width: _width,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: _localDate
                                ? LocalDateComposerSheet(
                                    draft: LocalDateComposerDraft.newDate(
                                      now: DateTime(2026, 9, 9, 9),
                                      timezone: 'Europe/Paris',
                                      environment:
                                          LocalDateEnvironment.instance,
                                    ).copyWith(startTime: '09:00:00'),
                                    siteFormats: const [
                                      'LLL',
                                      'YYYY-MM-DD [at] HH:mm',
                                    ],
                                  )
                                : Builder(builder: example.builder),
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
    );
  }
}
