import 'package:discourse_native/src/shell/platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('forumTabsEnabledFor', () {
    for (final platform in const [
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      test('supports native ${platform.name}', () {
        expect(forumTabsEnabledFor(platform: platform, isWeb: false), isTrue);
      });
    }

    for (final platform in const [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.fuchsia,
    ]) {
      test('does not support native ${platform.name}', () {
        expect(forumTabsEnabledFor(platform: platform, isWeb: false), isFalse);
      });
    }

    test('does not support web on any reported host platform', () {
      for (final platform in TargetPlatform.values) {
        expect(
          forumTabsEnabledFor(platform: platform, isWeb: true),
          isFalse,
          reason: platform.name,
        );
      }
    });
  });
}
