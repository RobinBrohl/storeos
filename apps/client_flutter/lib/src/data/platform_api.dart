abstract class PlatformApi {
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  });

  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  );
}

/// Purchasing uses PUT for full draft replacement and Supplier editing.
abstract interface class PurchasingApi implements PlatformApi {
  Future<Map<String, dynamic>> put(
    String token,
    String route,
    Map<String, dynamic> body,
  );
}
