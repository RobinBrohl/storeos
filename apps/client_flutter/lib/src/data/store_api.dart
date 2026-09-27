import 'package:storeos_api_contracts/api_contracts.dart';

abstract class StoreApi {
  Future<SessionResponse> login(LoginRequest request);

  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  });

  Future<void> logout(String token);
}

class StoreApiException implements Exception {
  const StoreApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
