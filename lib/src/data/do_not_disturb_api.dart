import '../models/do_not_disturb.dart';

abstract interface class DoNotDisturbApi {
  Future<DateTime> enterDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    required DoNotDisturbDuration duration,
    String? clientId,
  });

  Future<void> leaveDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });
}
