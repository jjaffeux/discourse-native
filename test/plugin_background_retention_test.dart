import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:discourse_native/src/shell/plugin_background_retention.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alpha = PluginId('alpha');
  const beta = PluginId('beta');
  const firstSite = 'https://one.example';
  const secondSite = 'https://two.example';

  late PluginBackgroundRetentionRegistry registry;
  late List<Set<String>> changes;

  setUp(() {
    changes = [];
    registry = PluginBackgroundRetentionRegistry(
      canRetain: const {firstSite, secondSite}.contains,
      onChanged: () => changes.add(Set.of(registry.siteUrls)),
    );
  });

  test('leases from multiple plugins and sites compose by set union', () {
    final alphaHost = registry.scopedTo(alpha);
    final betaHost = registry.scopedTo(beta);
    final alphaFirst = alphaHost.retain(firstSite);
    final alphaDuplicate = alphaHost.retain(firstSite);
    final betaFirst = betaHost.retain(firstSite);
    final betaSecond = betaHost.retain(secondSite);

    expect(registry.siteUrls, {firstSite, secondSite});
    expect(changes, [
      {firstSite},
      {firstSite, secondSite},
    ]);

    alphaFirst.release();
    alphaDuplicate.release();
    expect(registry.siteUrls, {firstSite, secondSite});

    betaFirst.release();
    expect(registry.siteUrls, {secondSite});
    betaSecond.release();
    expect(registry.siteUrls, isEmpty);
  });

  test('an owner can be revoked without touching another owner', () {
    final alphaHost = registry.scopedTo(alpha);
    alphaHost.retain(firstSite);
    registry.scopedTo(alpha).retain(secondSite);
    final betaLease = registry.scopedTo(beta).retain(firstSite);

    registry.releaseOwner(alpha);

    expect(registry.siteUrls, {firstSite});
    expect(betaLease.isReleased, isFalse);
    expect(() => alphaHost.retain(firstSite), throwsStateError);
    betaLease.release();
    expect(registry.siteUrls, isEmpty);
  });

  test('forgetting a site releases every owner claim for only that site', () {
    final alphaFirst = registry.scopedTo(alpha).retain(firstSite);
    final betaFirst = registry.scopedTo(beta).retain(firstSite);
    final betaSecond = registry.scopedTo(beta).retain(secondSite);

    registry.releaseSite(firstSite);

    expect(alphaFirst.isReleased, isTrue);
    expect(betaFirst.isReleased, isTrue);
    expect(betaSecond.isReleased, isFalse);
    expect(registry.siteUrls, {secondSite});
  });

  test('scoped hosts cannot retain unknown sites or recover the registry', () {
    final host = registry.scopedTo(alpha);

    expect(host, isNot(isA<PluginBackgroundRetentionRegistry>()));
    expect(
      () => host.retain('https://hostile.example'),
      throwsArgumentError,
    );
    expect(registry.siteUrls, isEmpty);
  });

  test('closing revokes every lease and disables retained scoped hosts', () {
    final host = registry.scopedTo(alpha);
    final lease = host.retain(firstSite);

    registry.close();

    expect(lease.isReleased, isTrue);
    expect(registry.siteUrls, isEmpty);
    expect(() => host.retain(firstSite), throwsStateError);
  });
}
