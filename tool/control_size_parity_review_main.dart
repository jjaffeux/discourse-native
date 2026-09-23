import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/styleguide/examples/mockup_control_sizes_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _Review());
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _mobile = false;
  bool _large = false;
  bool _rtl = false;
  StyleguideTheme _palette = StyleguideTheme.dark;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _palette
        .resolve(AppTheme.light)
        .copyWith(
          platform: _mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
        ),
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              const DText('Mockup control sizes', variant: DTextVariant.h2),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final palette in [
                    StyleguideTheme.light,
                    StyleguideTheme.dark,
                    StyleguideTheme.forest,
                    StyleguideTheme.plum,
                  ])
                    DButton(
                      label: Text(palette.label),
                      onPressed: () => setState(() => _palette = palette),
                    ),
                  DButton(
                    label: Text(_mobile ? 'Mobile 390' : 'Desktop 640'),
                    onPressed: () => setState(() => _mobile = !_mobile),
                  ),
                  DButton(
                    label: Text(_large ? 'Text 200%' : 'Text 100%'),
                    onPressed: () => setState(() => _large = !_large),
                  ),
                  DButton(
                    label: Text(_rtl ? 'RTL' : 'LTR'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                ],
              ),
              Center(
                child: SizedBox(
                  width: _mobile ? 390 : 640,
                  child: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
                      child: Directionality(
                        textDirection: _rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 16,
                          children: [
                            const Text('Production topic filters'),
                            TopicListFilterBar(
                              siteUrl: 'https://example.invalid',
                              categories: const [],
                              knownTags: const [],
                              selectedCategoryId: null,
                              selectedTagName: null,
                              taggingEnabled: true,
                              searchTags: (_) async => [],
                              onCategorySelected: (_) {},
                              onTagSelected: (_) {},
                              inline: true,
                              wrap: true,
                            ),
                            const MockupControlSizesExample(),
                          ],
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
