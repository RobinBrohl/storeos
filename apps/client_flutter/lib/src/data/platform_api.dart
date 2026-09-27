abstract class PlatformApi {
  Future<Map<String, dynamic>> get(String token, String route, {String? after});

  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  );
}
