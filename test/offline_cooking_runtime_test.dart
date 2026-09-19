import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter native assets cook through the shared worker', () async {
    final service = OfflineCookingService();
    addTearDown(service.dispose);
    final result = await service.cook(
      CookingRequest(
        raw: 'A **native** offline cook',
        snapshot: CookingSnapshot(
          siteId: 'test-site',
          accountId: 'test-account',
        ),
      ),
    );
    expect(result.failure, isNull);
    expect(result.html, '<p>A <strong>native</strong> offline cook</p>');
  });
}
