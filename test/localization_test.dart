import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/generated/app_localizations_en.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/foundation/count_label.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../tool/check_localizations.dart';

void main() {
  final originalLocale = Intl.defaultLocale;
  tearDown(() => Intl.defaultLocale = originalLocale);

  test('only English is offered, including on unsupported device locales', () {
    expect(AppLocalizations.supportedLocales, [const Locale('en')]);
    expect(
      resolveAppLocale([
        const Locale('fr', 'FR'),
        const Locale('de'),
      ], AppLocalizations.supportedLocales),
      const Locale('en'),
    );
    expect(Intl.defaultLocale, 'en');
    expect(appL10n.cancel, 'Cancel');
    expect(Intl.withLocale('en_GB', () => appL10n.cancel), 'Cancel');
    expect(Intl.withLocale('ja', () => appL10n.cancel), 'Cancel');
  });

  test('plural messages include zero, one, many and formatted counts', () {
    expect(countLabel(0, CountNoun.reply), '0 replies');
    expect(countLabel(1, CountNoun.reply), '1 reply');
    expect(countLabel(2, CountNoun.reply), '2 replies');
    expect(countLabel(1204, CountNoun.click, number: '1,204'), '1,204 clicks');
    expect(appL10n.namedReactions(1, 'heart'), '1 heart reaction');
    expect(appL10n.namedReactions(3, 'heart'), '3 heart reactions');
  });

  test('constant UI kit defaults and custom labels keep their behavior', () {
    expect(const DCalendarLabels().nextMonth, 'Next month');
    expect(
      const DCalendarLabels(nextMonth: 'Custom next').nextMonth,
      'Custom next',
    );
    expect(const DSpinner().semanticLabel, 'Loading');
    expect(const DSpinner(semanticLabel: null).semanticLabel, isNull);
    expect(const DSpinner(semanticLabel: 'Custom').semanticLabel, 'Custom');
  });

  testWidgets('Flutter delegates and app messages resolve together', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        localeListResolutionCallback: resolveAppLocale,
        home: Builder(
          builder: (context) {
            expect(Localizations.localeOf(context), const Locale('en'));
            expect(
              MaterialLocalizations.of(context).cancelButtonLabel,
              'Cancel',
            );
            return DButton(
              label: Text(AppLocalizations.of(context).cancel),
              onPressed: () {},
            );
          },
        ),
      ),
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('application UI boundaries contain no hard-coded language', () {
    expect(unlocalizedUiText(Directory('lib')), isEmpty);
  });

  test(
    'the source audit detects labels and preserves protocol identifiers',
    () {
      final directory = Directory.systemTemp.createTempSync('l10n-audit-');
      addTearDown(() => directory.deleteSync(recursive: true));
      File('${directory.path}/example.dart').writeAsStringSync("""
const wireName = 'Chat::Message';
class Example {
  const Example({this.label = 'Choose a channel'});
  final String label;
  String get title => 'Channel settings';
  Widget build() => Text('Save changes');
}
""");
      final findings = unlocalizedUiText(directory);
      expect(findings, hasLength(3));
      expect(findings.join('\n'), contains('Choose a channel'));
      expect(findings.join('\n'), contains('Channel settings'));
      expect(findings.join('\n'), contains('Save changes'));
      expect(findings.join('\n'), isNot(contains('Chat::Message')));
    },
  );

  testWidgets('constant widgets rebuild when their message locale changes', (
    tester,
  ) async {
    Widget app(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('en', 'GB')],
      localizationsDelegates: const [
        _TestLabelDelegate(),
        ...AppLocalizations.localizationsDelegates,
      ],
      home: const _LocalizedLabel(),
    );
    await tester.pumpWidget(app(const Locale('en')));
    expect(find.text('Cancel'), findsOneWidget);
    await tester.pumpWidget(app(const Locale('en', 'GB')));
    expect(find.text('Cancel (GB)'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });
}

class _LocalizedLabel extends StatelessWidget {
  const _LocalizedLabel();

  @override
  Widget build(BuildContext context) => Text(context.l10n.cancel);
}

class _TestMessages extends AppLocalizationsEn {
  _TestMessages(this.locale);
  final Locale locale;

  @override
  String get cancel => locale.countryCode == 'GB' ? 'Cancel (GB)' : 'Cancel';
}

class _TestLabelDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _TestLabelDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(_TestMessages(locale));

  @override
  bool shouldReload(_TestLabelDelegate old) => false;
}
