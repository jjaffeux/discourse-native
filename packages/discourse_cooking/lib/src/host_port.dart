import 'contracts.dart';

/// The application-owned port used by provisional cooking consumers.
abstract interface class CookingServicePort {
  Future<bool> start();
  Future<CookingResult> cook(CookingRequest request);
  Future<CookingResult> cookTransient(
    CookingRequest request, {
    required Future<void> abortTrigger,
  });
  void invalidate();
  Future<void> dispose();
}
