# Localization

The application currently supports English only. Flutter's `gen-l10n` generates
typed messages from `lib/l10n/app_en.arb`; `intl` supplies plural selection and
date/number formatting. The main app and standalone review entry points share
the generated delegates and supported locales. Unsupported device languages
resolve to English, including relative-time and framework controls.

## Adding or editing text

1. Add a stable, descriptive key to `lib/l10n/app_en.arb`, with an `@key`
   description that explains its context.
2. Put complete messages in the catalogue. Use typed placeholders for values and
   ICU plurals/selects for variations. Keep punctuation and word order in the
   message; do not append English suffixes or assemble sentences from words.
3. Use the generated accessor through `context.l10n` (or
   `AppLocalizations.of(context)`) in widgets
   or `appL10n` from `package:discourse_native/l10n/strings.dart` in presenters,
   models, services and default labels. `appL10n` follows the resolved app locale
   and also supports `Intl.withLocale` for isolated operations.
4. Run `flutter gen-l10n` and commit both the ARB and generated Dart files. The
   checked-in output also supports the compatibility app in `profiles/full`.
5. Run `dart run tool/check_localizations.dart` and
   `flutter test test/localization_test.dart`, plus tests for changed behavior.

Use `CountNoun` and `countLabel`/`countNoun` for shared count labels. Their plural
forms belong to ARB, including nouns rendered beside a separately styled number.
Use `DateFormat` and `NumberFormat` with the resolved locale for displayed dates
and numbers. Machine date formats, IANA zone names, URLs and stored identifiers
remain stable.

Native component labels keep their existing public parameters. Omitted labels
resolve from the catalogue; caller-supplied labels take precedence. Components
that accept explicit `null` to suppress a label retain that behavior.

## Adding a language

Copy `app_en.arb` to `app_<locale>.arb`, set `@@locale`, translate the messages,
and run `flutter gen-l10n`. The generator updates `supportedLocales`; no manual
language list or screen-by-screen migration is required. Retain placeholder
names/types and translate complete plural branches. Test the new language's
longer text, number/date formats, screen-reader labels and text direction.

Server-provided posts, names, categories, API error messages, source code,
protocol values, diagnostic identifiers and styleguide sample documents are
data, not application translation resources. The source audit checks literal
text at UI boundaries; it does not attempt to translate that content.
