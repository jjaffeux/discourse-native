import 'dart:io';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_decoration.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_directory.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_preferences.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/native_ui_evidence.dart';
import 'cakeday_fixture.dart';

void main() {
  testWidgets(
    'real Cakeday directory, preference and decorations render at desktop and phone sizes',
    (tester) async {
      await prepareNativeUiEvidence(tester);
      await tester.runAsync(() async {
        await (FontLoader('Lato')
              ..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('assets/fonts/Lato-Regular.ttf').readAsBytesSync(),
                  ),
                ),
              )
              ..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('assets/fonts/Lato-Bold.ttf').readAsBytesSync(),
                  ),
                ),
              ))
            .load();
      });
      for (final mobile in [false, true]) {
        final platform = mobile ? 'mobile' : 'desktop';
        tester.view.physicalSize = Size(
          mobile ? 390 : 1280,
          mobile ? 900 : 840,
        );
        tester.view.devicePixelRatio = 1;
        final f = CakedayFixture();
        f
                .transport
                .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
            (_) => page([for (var i = 1; i <= 6; i++) celebration(i)]);
        Widget shell(Widget child) => MaterialApp(
          theme: AppTheme.forBrightness(Brightness.light, fontFamily: 'Lato')
              .copyWith(
                platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
              ),
          builder: (context, child) => nativeUiEvidenceBuilder(
            context,
            MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: AppTextScaler(
                  platformScaler: TextScaler.noScaling,
                  appScale: 1,
                  baselineScale: mobile ? 17 / 14 : 1,
                ),
              ),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: DTouchTargets(child: DTouchFields(child: child)),
          ),
        );
        await tester.pumpWidget(
          shell(
            CakedayDirectory(
              site: cakedaySite,
              query: birthdayQuery,
              controller: f.controller,
              navigation: f.navigation,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('member1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureNativeUi(tester, '$platform-directory');
        final dates = CakedayDates.read({
          'cakedate': '2020-11-01',
          'birthdate': '1992-11-01',
        })!;
        await tester.pumpWidget(
          shell(
            DPageSurface.headed(
              title: const Text('A community milestone'),
              bodyBuilder: (context, header) => SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header.spacer,
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: DCard(
                        children: [
                          DCardContent(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const DAvatar(
                                      fallback: DAvatarFallback(
                                        child: Text('MC'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('maya'),
                                    const SizedBox(width: 8),
                                    CakedayDecoration(
                                      controller: f.controller,
                                      site: cakedaySite,
                                      dates: dates,
                                      userId: 4,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const DText(
                                  'Six years in the community today. Thanks for all the conversations along the way!',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DTooltip), findsNWidgets(2));
        await tester.longPress(
          find.byWidgetPredicate(
            (w) => w is DTooltip && w.message == 'Today is my birthday!',
          ),
        );
        await tester.pumpAndSettle();
        await captureNativeUi(tester, '$platform-decoration');
        var value = CakedayPreferences(CakedayBirthday.create(11, 1));
        await tester.pumpWidget(
          shell(
            DPageSurface.headed(
              title: const Text('Birthday'),
              bodyBuilder: (context, header) => SingleChildScrollView(
                child: Column(
                  children: [
                    header.spacer,
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: StatefulBuilder(
                        builder: (context, setState) => CakedayBirthdayEditor(
                          value: value,
                          editable: true,
                          onChanged: (v) => setState(() => value = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await captureNativeUi(tester, '$platform-preferences');
        await tester.tap(find.text('Clear birthday'));
        await tester.pumpAndSettle();
        expect(value.payload, {'date_of_birth': ''});
        f.controller.setForeground(false);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        f.dispose();
      }
      tester.view.reset();
    },
  );
}
