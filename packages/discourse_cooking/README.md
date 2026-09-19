# Discourse offline cooking

A bounded worker-owned Discourse JavaScript engine for native Dart/Flutter applications. No UI integration or network resolution is performed by this package.

```dart
import 'package:discourse_cooking/discourse_cooking.dart';

final cooker = OfflineCookingService();
try {
  final result = await cooker.cook(CookingRequest(
    raw: '**Hello** :smile:',
    profile: CookingProfile.chat,
    snapshot: CookingSnapshot(
      siteId: 'forum.example',
      accountId: 'current-account',
      baseUrl: 'https://forum.example',
    ),
  ));
  // Feed result.html to the existing CookedHtml renderer. A typed failure
  // contains safe readable fallback HTML. Server HTML remains authoritative.
} finally {
  await cooker.dispose();
}
```

See [milestone evidence](../../docs/cooking/milestone-1.md) for architecture, exact validation, resource limits, benchmarks, platform limitations and remaining milestones. [JS bundle documentation](js/README.md) describes provenance, build/update commands and snapshot shapes.

QuickJS-NG is MIT-licensed; the bundled Discourse code is GPL-2.0-only. The generated [package notices](LICENSE) are also available to Flutter package-license aggregation. See [Discourse license](js/vendor/LICENSE.txt), [bundled module notices](js/NOTICE.txt), and [QuickJS license](vendor/quickjs/LICENSE). The root MIT license does not relicense the bundled upstream code.
