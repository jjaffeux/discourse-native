import 'package:discourse_native/src/models/site_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the automatic image gallery setting with its core default', () {
    expect(const SiteConfig.unknown().enableAutoGridImages, isTrue);
    expect(SiteConfig.fromSettings(const {}).enableAutoGridImages, isTrue);
    expect(
      SiteConfig.fromSettings(const {
        'enable_auto_grid_images': false,
      }).enableAutoGridImages,
      isFalse,
    );
  });

  test('persists the automatic image gallery setting through copies', () {
    final disabled = SiteConfig.fromSettings(const {
      'enable_auto_grid_images': false,
    });
    final restored = SiteConfig.fromJson(disabled.toJson());

    expect(restored, disabled);
    expect(restored.hashCode, disabled.hashCode);
    expect(
      disabled.withPlugins(disabled.plugins).enableAutoGridImages,
      isFalse,
    );
    expect(SiteConfig.fromJson(const {}).enableAutoGridImages, isTrue);
  });
}
